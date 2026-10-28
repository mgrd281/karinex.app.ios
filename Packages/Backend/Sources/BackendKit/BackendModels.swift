import Core
import Foundation

// MARK: - RemoteAppConfig

/// `GET /v1/app/config`: values the owner can change without an app release.
public struct RemoteAppConfig: Sendable, Hashable, Codable {
    /// The support hours.
    public let supportHours: SupportHours
    /// The WhatsApp number in international format without `+` or spaces, e.g. `4940123456`.
    /// Only ever used to build a `https://wa.me/` link, never shown as a number to call.
    public let whatsappNumber: String?
    /// The live chat page, if the owner offers one.
    public let liveChatURL: URL?
    /// The support e-mail address.
    public let supportEmail: String
    /// Server-side feature switches, e.g. `licenseVault`.
    public let featureFlags: [String: Bool]
    /// The oldest app version the backend still supports, e.g. `0.2.0`.
    public let minSupportedAppVersion: String?

    /// Creates a configuration.
    public init(
        supportHours: SupportHours,
        whatsappNumber: String?,
        liveChatURL: URL?,
        supportEmail: String,
        featureFlags: [String: Bool],
        minSupportedAppVersion: String?
    ) {
        self.supportHours = supportHours
        self.whatsappNumber = whatsappNumber
        self.liveChatURL = liveChatURL
        self.supportEmail = supportEmail
        self.featureFlags = featureFlags
        self.minSupportedAppVersion = minSupportedAppVersion
    }

    /// The values that apply while the backend is unavailable: the hours and e-mail address of
    /// PROMPT.md 2, no WhatsApp number and no live chat (they come only from the backend).
    public static let fallback = RemoteAppConfig(
        supportHours: .standard,
        whatsappNumber: nil,
        liveChatURL: nil,
        supportEmail: "kundenservice@karinex.de",
        featureFlags: [:],
        minSupportedAppVersion: nil
    )

    private enum CodingKeys: String, CodingKey {
        case supportHours, whatsappNumber, supportEmail, featureFlags, minSupportedAppVersion
        case liveChatURL = "liveChatUrl"
    }

    /// Decodes the contract shape; missing optional members take the fallback values.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        supportHours = try container.decodeIfPresent(SupportHours.self, forKey: .supportHours) ?? .standard
        whatsappNumber = try container.decodeIfPresent(String.self, forKey: .whatsappNumber).flatMap(Self.digits)
        liveChatURL = try container.decodeIfPresent(URL.self, forKey: .liveChatURL).flatMap { $0.scheme == "https" ? $0 : nil }
        supportEmail = try container.decodeIfPresent(String.self, forKey: .supportEmail) ?? Self.fallback.supportEmail
        featureFlags = try container.decodeIfPresent([String: Bool].self, forKey: .featureFlags) ?? [:]
        minSupportedAppVersion = try container.decodeIfPresent(String.self, forKey: .minSupportedAppVersion)
    }

    /// The digits of `text`, or `nil` when there are fewer than six.
    private static func digits(_ text: String) -> String? {
        let digits = text.filter(\.isASCII).filter(\.isNumber)
        return digits.count >= 6 ? digits : nil
    }

    /// The `https://wa.me/` link with a prefilled message, or `nil` without a number.
    public func whatsAppURL(message: String?) -> URL? {
        guard let whatsappNumber else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wa.me"
        components.path = "/\(whatsappNumber)"
        if let message, !message.isEmpty {
            components.queryItems = [URLQueryItem(name: "text", value: message)]
        }
        return components.url
    }

    /// Whether `appVersion` (e.g. `0.2.0`) is older than `minSupportedAppVersion`.
    public func requiresUpdate(appVersion: String) -> Bool {
        guard let minSupportedAppVersion else { return false }
        return appVersion.compare(minSupportedAppVersion, options: .numeric) == .orderedAscending
    }
}

// MARK: - SupportHours

/// The hours in which support answers, computed in `timeZone` (Europe/Berlin), shown in the
/// user's locale.
public struct SupportHours: Sendable, Hashable, Codable {
    /// The time zone of the hours, `Europe/Berlin`.
    public let timeZoneIdentifier: String
    /// ISO weekdays (1 Monday to 7 Sunday) on which support answers.
    public let weekdays: [Int]
    /// Opening time in minutes after midnight, e.g. 480 for 08:00.
    public let opensAtMinute: Int
    /// Closing time in minutes after midnight, e.g. 1380 for 23:00.
    public let closesAtMinute: Int

    /// Creates the hours.
    public init(timeZoneIdentifier: String, weekdays: [Int], opensAtMinute: Int, closesAtMinute: Int) {
        self.timeZoneIdentifier = timeZoneIdentifier
        self.weekdays = weekdays
        self.opensAtMinute = opensAtMinute
        self.closesAtMinute = closesAtMinute
    }

    /// Monday to Sunday, 08:00 to 23:00 Europe/Berlin (PROMPT.md 2).
    public static let standard = SupportHours(
        timeZoneIdentifier: "Europe/Berlin",
        weekdays: [1, 2, 3, 4, 5, 6, 7],
        opensAtMinute: 8 * 60,
        closesAtMinute: 23 * 60
    )

    /// Whether support answers at `date`.
    public func isOpen(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 3600) ?? .current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday, let hour = components.hour, let minute = components.minute else { return false }
        // Calendar weekdays start with 1 = Sunday; ISO weekdays with 1 = Monday.
        let isoWeekday = weekday == 1 ? 7 : weekday - 1
        let minuteOfDay = hour * 60 + minute
        return weekdays.contains(isoWeekday) && minuteOfDay >= opensAtMinute && minuteOfDay < closesAtMinute
    }

    /// Whether the hours cover every day of the week.
    public var isEveryDay: Bool {
        Set(weekdays) == Set(1...7)
    }

    /// The opening and closing time on `date`'s day as dates, for locale-aware formatting
    /// (`08:00` in Germany, `8:00 AM` in an English locale with a 12-hour clock).
    public func interval(on date: Date) -> (opens: Date, closes: Date)? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 3600) ?? .current
        let start = calendar.startOfDay(for: date)
        guard let opens = calendar.date(byAdding: .minute, value: opensAtMinute, to: start),
              let closes = calendar.date(byAdding: .minute, value: closesAtMinute, to: start)
        else { return nil }
        return (opens, closes)
    }

    private enum CodingKeys: String, CodingKey {
        case timeZone, weekdays, opensAt, closesAt
    }

    /// Decodes `{"timeZone": "Europe/Berlin", "weekdays": [1, ...], "opensAt": "08:00", "closesAt": "23:00"}`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timeZoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timeZone) ?? Self.standard.timeZoneIdentifier
        weekdays = try (container.decodeIfPresent([Int].self, forKey: .weekdays) ?? Self.standard.weekdays).filter { (1...7).contains($0) }
        guard let opens = try Self.minute(container.decode(String.self, forKey: .opensAt)),
              let closes = try Self.minute(container.decode(String.self, forKey: .closesAt)),
              opens < closes
        else {
            throw DecodingError.dataCorruptedError(forKey: .opensAt, in: container, debugDescription: "Hours must be HH:mm, opening first.")
        }
        opensAtMinute = opens
        closesAtMinute = closes
    }

    /// Encodes the contract shape.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(timeZoneIdentifier, forKey: .timeZone)
        try container.encode(weekdays, forKey: .weekdays)
        try container.encode(Self.text(opensAtMinute), forKey: .opensAt)
        try container.encode(Self.text(closesAtMinute), forKey: .closesAt)
    }

    static func minute(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...24).contains(hour), (0..<60).contains(minute), hour * 60 + minute <= 24 * 60
        else { return nil }
        return hour * 60 + minute
    }

    static func text(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
}

// MARK: - Orders

/// The delivery state the fulfillment service reports for an order.
public enum DeliveryStatus: String, Sendable, Hashable, Codable {
    /// Paid; keys or goods are on their way.
    case pending
    /// The license keys were delivered by e-mail.
    case delivered
    /// The physical goods were shipped.
    case shipped

    /// Decodes unknown values as `pending`, the safe assumption.
    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = DeliveryStatus(rawValue: value) ?? .pending
    }
}

/// `GET /v1/app/orders`: an order as the fulfillment service knows it.
public struct BackendOrderStatus: Sendable, Hashable, Codable, Identifiable {
    /// The numeric Shopify order ID, e.g. `5678`.
    public let orderID: String
    /// The order name, e.g. `#1042`.
    public let name: String?
    /// The delivery state.
    public let deliveryStatus: DeliveryStatus
    /// Whether license keys belong to the order.
    public let hasLicenses: Bool
    /// Whether an invoice PDF exists.
    public let hasInvoice: Bool

    /// The order ID.
    public var id: String {
        orderID
    }

    /// Creates a status.
    public init(orderID: String, name: String?, deliveryStatus: DeliveryStatus, hasLicenses: Bool, hasInvoice: Bool) {
        self.orderID = orderID
        self.name = name
        self.deliveryStatus = deliveryStatus
        self.hasLicenses = hasLicenses
        self.hasInvoice = hasInvoice
    }

    private enum CodingKeys: String, CodingKey {
        case orderID = "orderId"
        case name, deliveryStatus, hasLicenses, hasInvoice
    }

    /// Decodes the contract shape; `hasInvoice` defaults to `true`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderID = try container.decode(String.self, forKey: .orderID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        deliveryStatus = try container.decode(DeliveryStatus.self, forKey: .deliveryStatus)
        hasLicenses = try container.decodeIfPresent(Bool.self, forKey: .hasLicenses) ?? false
        hasInvoice = try container.decodeIfPresent(Bool.self, forKey: .hasInvoice) ?? true
    }
}

// MARK: - Licenses

/// A delivered license key (`GET /v1/app/orders/{orderId}/licenses`).
///
/// `description` and the mirror never contain the key.
public struct LicenseKey: Sendable, Hashable, Codable, Identifiable, CustomStringConvertible, CustomReflectable {
    /// The Shopify line item ID the key belongs to.
    public let lineItemID: String
    /// The product title.
    public let productTitle: String
    /// The SKU, if any.
    public let sku: String?
    /// The key.
    public let key: String
    /// When it was delivered.
    public let deliveredAt: Date?
    /// The activation guide, if the shop links one.
    public let activationGuideURL: URL?
    /// The order the key belongs to (set by the client, not part of the response).
    public let orderID: String

    /// Line item and key together identify a key (a line with quantity 2 has two keys).
    public var id: String {
        "\(orderID)-\(lineItemID)-\(SHA256Fingerprint.of(key))"
    }

    /// Creates a key.
    public init(
        lineItemID: String,
        productTitle: String,
        sku: String?,
        key: String,
        deliveredAt: Date?,
        activationGuideURL: URL?,
        orderID: String
    ) {
        self.lineItemID = lineItemID
        self.productTitle = productTitle
        self.sku = sku
        self.key = key
        self.deliveredAt = deliveredAt
        self.activationGuideURL = activationGuideURL
        self.orderID = orderID
    }

    /// The same key for `orderID`.
    public func assigned(to orderID: String) -> LicenseKey {
        LicenseKey(
            lineItemID: lineItemID,
            productTitle: productTitle,
            sku: sku,
            key: key,
            deliveredAt: deliveredAt,
            activationGuideURL: activationGuideURL,
            orderID: orderID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case lineItemID = "lineItemId"
        case activationGuideURL = "activationGuideUrl"
        case productTitle, sku, key, deliveredAt, orderID = "orderId"
    }

    /// Decodes the contract shape (`deliveredAt` ISO 8601; `orderId` only in the Keychain cache).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lineItemID = try container.decode(String.self, forKey: .lineItemID)
        productTitle = try container.decode(String.self, forKey: .productTitle)
        sku = try container.decodeIfPresent(String.self, forKey: .sku)
        key = try container.decode(String.self, forKey: .key)
        deliveredAt = try container.decodeIfPresent(String.self, forKey: .deliveredAt).flatMap(BackendDate.parse)
        activationGuideURL = try container.decodeIfPresent(URL.self, forKey: .activationGuideURL)
            .flatMap { $0.scheme == "https" ? $0 : nil }
        orderID = try container.decodeIfPresent(String.self, forKey: .orderID) ?? ""
    }

    /// Encodes the contract shape plus `orderId`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lineItemID, forKey: .lineItemID)
        try container.encode(productTitle, forKey: .productTitle)
        try container.encodeIfPresent(sku, forKey: .sku)
        try container.encode(key, forKey: .key)
        try container.encodeIfPresent(deliveredAt.map(BackendDate.format), forKey: .deliveredAt)
        try container.encodeIfPresent(activationGuideURL, forKey: .activationGuideURL)
        try container.encode(orderID, forKey: .orderID)
    }

    /// A log-safe description.
    public var description: String {
        "LicenseKey(order: \(orderID), lineItem: \(lineItemID), product: \(productTitle), key: <redacted>)"
    }

    /// A mirror without the key.
    public var customMirror: Mirror {
        Mirror(self, children: ["description": description], displayStyle: .struct)
    }
}

/// The answer of the licenses endpoint.
public enum LicenseDelivery: Sendable, Hashable {
    /// The keys of the order.
    case delivered([LicenseKey])
    /// The backend has not delivered the keys yet (HTTP 202).
    case pending
}

// MARK: - Invoice

/// `GET /v1/app/orders/{orderId}/invoice`: a short-lived signed PDF link.
public struct InvoiceLink: Sendable, Hashable, Codable {
    /// The PDF URL (https only).
    public let url: URL
    /// When the link stops working.
    public let expiresAt: Date?

    /// Creates a link.
    public init(url: URL, expiresAt: Date?) {
        self.url = url
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case url, expiresAt
    }

    /// Decodes the contract shape; links that are not https are rejected.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let url = try container.decode(URL.self, forKey: .url)
        guard url.scheme == "https" else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Invoice links must use https.")
        }
        self.url = url
        expiresAt = try container.decodeIfPresent(String.self, forKey: .expiresAt).flatMap(BackendDate.parse)
    }

    /// Encodes the contract shape.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(expiresAt.map(BackendDate.format), forKey: .expiresAt)
    }
}

// MARK: - Devices

/// `POST /v1/app/devices`: an APNs token with the push consents (Phase 3).
public struct DeviceRegistration: Sendable, Hashable, Encodable {
    /// The consents per push category.
    public struct Consent: Sendable, Hashable, Encodable {
        /// Order and delivery updates.
        public let orderUpdates: Bool
        /// Deal announcements.
        public let deals: Bool

        /// Creates the consents.
        public init(orderUpdates: Bool, deals: Bool) {
            self.orderUpdates = orderUpdates
            self.deals = deals
        }
    }

    /// The APNs device token as hex.
    public let apnsToken: String
    /// The UI language, e.g. `de`.
    public let locale: String
    /// The market country, e.g. `DE`.
    public let country: String
    /// The consents.
    public let consent: Consent

    /// `production` for TestFlight and App Store builds, `sandbox` for debug builds.
    public let environment: String

    /// Creates a registration.
    public init(apnsToken: String, locale: String, country: String, consent: Consent, environment: String = "production") {
        self.apnsToken = apnsToken
        self.locale = locale
        self.country = country
        self.consent = consent
        self.environment = environment
    }
}

// MARK: - Inbox

/// One message of "Neuigkeiten" (`GET /v1/app/notifications`).
///
/// Messages of the store owner carry their own title and text. Automatic messages (back in
/// stock, order paid, keys delivered) carry only parameters; the app writes their text in the
/// customer's language.
public struct InboxMessage: Sendable, Hashable, Identifiable, Decodable {
    /// The kind of message.
    public enum Kind: Sendable, Hashable {
        /// Written by the store owner for all customers.
        case broadcast
        /// A product the customer asked about is available again.
        case restock
        /// An order of the customer was paid.
        case orderPaid
        /// The keys of an order were delivered.
        case licenseDelivered
        /// A kind this app version does not know; not shown.
        case unknown

        init(raw: String) {
            switch raw {
            case "broadcast": self = .broadcast
            case "restock": self = .restock
            case "order_paid": self = .orderPaid
            case "license_delivered": self = .licenseDelivered
            default: self = .unknown
            }
        }
    }

    /// Stable identity.
    public let id: String
    /// The kind.
    public let kind: Kind
    /// The short line above the card, set by the store owner.
    public let label: String?
    /// The title (empty for automatic messages).
    public let title: String
    /// The text (empty for automatic messages).
    public let body: String
    /// An `https` product image.
    public let imageURL: URL?
    /// The product the message is about, if any.
    public let productHandle: String?
    /// Parameters of automatic messages: `productTitle`, `orderName`, `orderId`.
    public let params: [String: String]
    /// When the message was created.
    public let createdAt: Date

    /// Creates a message, e.g. for previews and tests.
    public init(
        id: String,
        kind: Kind,
        label: String? = nil,
        title: String = "",
        body: String = "",
        imageURL: URL? = nil,
        productHandle: String? = nil,
        params: [String: String] = [:],
        createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.title = title
        self.body = body
        self.imageURL = imageURL
        self.productHandle = productHandle
        self.params = params
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, title, body, imageUrl, productHandle, params, createdAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = try Kind(raw: container.decode(String.self, forKey: .kind))
        label = try container.decodeIfPresent(String.self, forKey: .label)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try container.decodeIfPresent(String.self, forKey: .body) ?? ""
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageUrl)
            .flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" ? $0 : nil }
        productHandle = try container.decodeIfPresent(String.self, forKey: .productHandle)
        params = try container.decodeIfPresent([String: String].self, forKey: .params) ?? [:]
        let created = try container.decode(String.self, forKey: .createdAt)
        guard let date = BackendDate.parse(created) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: container, debugDescription: "Invalid date")
        }
        createdAt = date
    }
}

/// The body of `GET /v1/app/notifications`.
struct InboxPage: Decodable {
    let items: [InboxMessage]
}

/// `POST /v1/app/restock`: "Benachrichtigen, wenn verfügbar".
public struct RestockWatch: Sendable, Hashable, Encodable {
    /// The product handle.
    public let productHandle: String
    /// The variant ID (a Shopify GID or the number).
    public let variantId: String
    /// The product title, for the message in the customer's language.
    public let productTitle: String

    /// Creates a watch.
    public init(productHandle: String, variantID: String, productTitle: String) {
        self.productHandle = productHandle
        variantId = variantID
        self.productTitle = productTitle
    }
}

// MARK: - Helpers

/// ISO 8601 dates of the contract.
enum BackendDate {
    static func parse(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: Date.ISO8601FormatStyle()) {
            return date
        }
        return try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }

    static func format(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle())
    }
}

/// A short, non-reversible fingerprint used to tell keys apart in identifiers without the key
/// itself appearing in them.
enum SHA256Fingerprint {
    static func of(_ text: String) -> String {
        SHA256.hash(text).prefix(6).map { String(format: "%02x", $0) }.joined()
    }
}
