import Foundation

// MARK: - Customer

/// The signed-in customer (Customer Account API `Customer`). Only what the account screen
/// shows is selected.
public struct Customer: Sendable, Hashable, Decodable, Identifiable {
    /// The customer GID.
    public let id: ShopifyID
    /// The name Shopify shows, e.g. "Anna Schmidt", or the e-mail address when no name is set.
    public let displayName: String
    /// The first name, if any.
    public let firstName: String?
    /// The last name, if any.
    public let lastName: String?
    /// The login e-mail address, if any.
    public let emailAddress: String?
    /// The default address, if any.
    public let defaultAddress: CustomerAddress?

    /// Creates a customer.
    public init(
        id: ShopifyID,
        displayName: String,
        firstName: String?,
        lastName: String?,
        emailAddress: String?,
        defaultAddress: CustomerAddress?
    ) {
        self.id = id
        self.displayName = displayName
        self.firstName = firstName
        self.lastName = lastName
        self.emailAddress = emailAddress
        self.defaultAddress = defaultAddress
    }

    private enum CodingKeys: String, CodingKey {
        case id, displayName, firstName, lastName, emailAddress, defaultAddress
    }

    private struct EmailAddress: Decodable {
        let emailAddress: String?
    }

    /// Decodes `emailAddress { emailAddress }`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        firstName = try container.decodeIfPresent(String.self, forKey: .firstName)
        lastName = try container.decodeIfPresent(String.self, forKey: .lastName)
        emailAddress = try container.decodeIfPresent(EmailAddress.self, forKey: .emailAddress)?.emailAddress
        defaultAddress = try container.decodeIfPresent(CustomerAddress.self, forKey: .defaultAddress)
    }
}

// MARK: - CustomerAddress

/// A postal address of the customer (Customer Account API `CustomerAddress`). Contact fields
/// are deliberately not requested: the app needs only the postal lines.
public struct CustomerAddress: Sendable, Hashable, Codable, Identifiable {
    /// The address GID.
    public let id: ShopifyID
    /// First name.
    public let firstName: String?
    /// Last name.
    public let lastName: String?
    /// Company.
    public let company: String?
    /// Street and house number.
    public let address1: String?
    /// Additional address line.
    public let address2: String?
    /// Postal code.
    public let zip: String?
    /// City.
    public let city: String?
    /// Province or state name, if the country has them.
    public let province: String?
    /// Province code, e.g. `BY`, if the country has them.
    public let zoneCode: String?
    /// Country name in the shop language.
    public let country: String?
    /// ISO 3166-1 alpha-2 country code, e.g. `DE`.
    public let territoryCode: String?

    /// Creates an address.
    public init(
        id: ShopifyID,
        firstName: String?,
        lastName: String?,
        company: String?,
        address1: String?,
        address2: String?,
        zip: String?,
        city: String?,
        province: String?,
        zoneCode: String?,
        country: String?,
        territoryCode: String?
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.company = company
        self.address1 = address1
        self.address2 = address2
        self.zip = zip
        self.city = city
        self.province = province
        self.zoneCode = zoneCode
        self.country = country
        self.territoryCode = territoryCode
    }

    /// The non-empty lines of the address for display: name, company, street lines,
    /// "zip city", province and country.
    public var lines: [String] {
        let name = [firstName, lastName].compactMap(Self.trimmed).joined(separator: " ")
        let cityLine = [zip, city].compactMap(Self.trimmed).joined(separator: " ")
        let candidates: [String?] = [name, company, address1, address2, cityLine, province, country]
        return candidates.compactMap { Self.trimmed($0) }
    }

    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}

// MARK: - CustomerAddressInput

/// The fields of a new or changed address (Customer Account API `CustomerAddressInput`).
/// `nil` fields are left out of the request.
public struct CustomerAddressInput: Sendable, Hashable, Encodable {
    /// First name.
    public var firstName: String?
    /// Last name.
    public var lastName: String?
    /// Company.
    public var company: String?
    /// Street and house number.
    public var address1: String?
    /// Additional address line.
    public var address2: String?
    /// Postal code.
    public var zip: String?
    /// City.
    public var city: String?
    /// Province code, if the country has provinces.
    public var zoneCode: String?
    /// ISO 3166-1 alpha-2 country code.
    public var territoryCode: String?

    /// Creates the input.
    public init(
        firstName: String? = nil,
        lastName: String? = nil,
        company: String? = nil,
        address1: String? = nil,
        address2: String? = nil,
        zip: String? = nil,
        city: String? = nil,
        zoneCode: String? = nil,
        territoryCode: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.company = company
        self.address1 = address1
        self.address2 = address2
        self.zip = zip
        self.city = city
        self.zoneCode = zoneCode
        self.territoryCode = territoryCode
    }

    /// The input with the values of `address`, for editing.
    public init(address: CustomerAddress) {
        self.init(
            firstName: address.firstName,
            lastName: address.lastName,
            company: address.company,
            address1: address.address1,
            address2: address.address2,
            zip: address.zip,
            city: address.city,
            zoneCode: address.zoneCode,
            territoryCode: address.territoryCode
        )
    }
}

// MARK: - Order statuses

/// The payment state of an order (Customer Account API `OrderFinancialStatus`).
public enum OrderFinancialStatus: Sendable, Hashable, Codable {
    case authorized, expired, paid, partiallyPaid, partiallyRefunded, pending, refunded, voided
    /// A value this version of the app does not know.
    case unknown(String)

    private static let known: [String: OrderFinancialStatus] = [
        "AUTHORIZED": .authorized, "EXPIRED": .expired, "PAID": .paid, "PARTIALLY_PAID": .partiallyPaid,
        "PARTIALLY_REFUNDED": .partiallyRefunded, "PENDING": .pending, "REFUNDED": .refunded, "VOIDED": .voided,
    ]

    /// Creates the status from its GraphQL value.
    public init(rawValue: String) {
        self = Self.known[rawValue] ?? .unknown(rawValue)
    }

    /// The GraphQL value.
    public var rawValue: String {
        if case let .unknown(value) = self { return value }
        return Self.known.first { $0.value == self }?.key ?? ""
    }

    /// Decodes the GraphQL enum value.
    public init(from decoder: any Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes the GraphQL enum value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    /// Whether the order counts as paid for the timeline (paid or partly refunded afterwards).
    public var isPaid: Bool {
        switch self {
        case .paid, .partiallyRefunded, .refunded: true
        case .authorized, .expired, .partiallyPaid, .pending, .voided, .unknown: false
        }
    }
}

/// The aggregated fulfillment state of an order (Customer Account API `OrderFulfillmentStatus`).
public enum OrderFulfillmentStatus: Sendable, Hashable, Codable {
    case fulfilled, inProgress, onHold, open, partiallyFulfilled, pendingFulfillment, restocked, scheduled, unfulfilled
    /// A value this version of the app does not know.
    case unknown(String)

    private static let known: [String: OrderFulfillmentStatus] = [
        "FULFILLED": .fulfilled, "IN_PROGRESS": .inProgress, "ON_HOLD": .onHold, "OPEN": .open,
        "PARTIALLY_FULFILLED": .partiallyFulfilled, "PENDING_FULFILLMENT": .pendingFulfillment, "RESTOCKED": .restocked,
        "SCHEDULED": .scheduled, "UNFULFILLED": .unfulfilled,
    ]

    /// Creates the status from its GraphQL value.
    public init(rawValue: String) {
        self = Self.known[rawValue] ?? .unknown(rawValue)
    }

    /// The GraphQL value.
    public var rawValue: String {
        if case let .unknown(value) = self { return value }
        return Self.known.first { $0.value == self }?.key ?? ""
    }

    /// Decodes the GraphQL enum value.
    public init(from decoder: any Decoder) throws {
        try self.init(rawValue: decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes the GraphQL enum value.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - CustomerOrder

/// An order of the customer (Customer Account API `Order`). Line items and fulfillments are
/// present in the detail query and empty in the list.
public struct CustomerOrder: Sendable, Hashable, Decodable, Identifiable {
    /// The order GID.
    public let id: ShopifyID
    /// The order name, e.g. `#1042`.
    public let name: String
    /// The customer-facing confirmation number, if any.
    public let confirmationNumber: String?
    /// When the order was processed.
    public let processedAt: Date
    /// When the order was cancelled, if it was.
    public let cancelledAt: Date?
    /// The payment state, if known.
    public let financialStatus: OrderFinancialStatus?
    /// The fulfillment state.
    public let fulfillmentStatus: OrderFulfillmentStatus?
    /// The total, exactly as Shopify returns it.
    public let totalPrice: MoneyV2
    /// The subtotal, if any.
    public let subtotal: MoneyV2?
    /// The taxes, if any.
    public let totalTax: MoneyV2?
    /// The shipping costs.
    public let totalShipping: MoneyV2?
    /// The line items: all of them in the detail, the first five (name, quantity and photo
    /// only) in the order list.
    public let lineItems: [OrderLineItem]
    /// The fulfillments (detail only).
    public let fulfillments: [OrderFulfillment]

    /// Creates an order.
    public init(
        id: ShopifyID,
        name: String,
        confirmationNumber: String?,
        processedAt: Date,
        cancelledAt: Date?,
        financialStatus: OrderFinancialStatus?,
        fulfillmentStatus: OrderFulfillmentStatus?,
        totalPrice: MoneyV2,
        subtotal: MoneyV2?,
        totalTax: MoneyV2?,
        totalShipping: MoneyV2?,
        lineItems: [OrderLineItem],
        fulfillments: [OrderFulfillment]
    ) {
        self.id = id
        self.name = name
        self.confirmationNumber = confirmationNumber
        self.processedAt = processedAt
        self.cancelledAt = cancelledAt
        self.financialStatus = financialStatus
        self.fulfillmentStatus = fulfillmentStatus
        self.totalPrice = totalPrice
        self.subtotal = subtotal
        self.totalTax = totalTax
        self.totalShipping = totalShipping
        self.lineItems = lineItems
        self.fulfillments = fulfillments
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, confirmationNumber, processedAt, cancelledAt, financialStatus, fulfillmentStatus
        case totalPrice, subtotal, totalTax, totalShipping, lineItems, fulfillments
    }

    /// Decodes the Customer Account API shape (`DateTime` strings, connections with `nodes`).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        confirmationNumber = try container.decodeIfPresent(String.self, forKey: .confirmationNumber)
        processedAt = try ArticleCoding.decodeDate(from: container, forKey: .processedAt)
        cancelledAt = try container.decodeIfPresent(String.self, forKey: .cancelledAt).flatMap(ArticleCoding.date(from:))
        financialStatus = try container.decodeIfPresent(OrderFinancialStatus.self, forKey: .financialStatus)
        fulfillmentStatus = try container.decodeIfPresent(OrderFulfillmentStatus.self, forKey: .fulfillmentStatus)
        totalPrice = try container.decode(MoneyV2.self, forKey: .totalPrice)
        subtotal = try container.decodeIfPresent(MoneyV2.self, forKey: .subtotal)
        totalTax = try container.decodeIfPresent(MoneyV2.self, forKey: .totalTax)
        totalShipping = try container.decodeIfPresent(MoneyV2.self, forKey: .totalShipping)
        lineItems = try container.decodeIfPresent(Connection<OrderLineItem>.self, forKey: .lineItems)?.nodes ?? []
        fulfillments = try container.decodeIfPresent(Connection<OrderFulfillment>.self, forKey: .fulfillments)?.nodes ?? []
    }

    /// The numeric part of the GID, e.g. `5678` of `gid://shopify/Order/5678`, used by the
    /// backend and in support messages.
    public var numericID: String? {
        id.resourceID
    }
}

// MARK: - OrderLineItem

/// A line of an order (Customer Account API `LineItem`).
public struct OrderLineItem: Sendable, Hashable, Decodable, Identifiable {
    /// The line item GID.
    public let id: ShopifyID
    /// The product name.
    public let name: String
    /// The variant title, if the variant has one.
    public let variantTitle: String?
    /// The quantity.
    public let quantity: Int
    /// The unit price without discounts, if known.
    public let price: MoneyV2?
    /// The line total Shopify reports, if known.
    public let total: MoneyV2?
    /// The image, if any.
    public let image: ShopifyImage?
    /// The variant GID, `nil` for custom lines or variants deleted since; "Erneut kaufen" puts
    /// it back into the cart.
    public let variantID: ShopifyID?

    /// Creates a line item.
    public init(
        id: ShopifyID,
        name: String,
        variantTitle: String?,
        quantity: Int,
        price: MoneyV2?,
        total: MoneyV2?,
        image: ShopifyImage?,
        variantID: ShopifyID? = nil
    ) {
        self.id = id
        self.name = name
        self.variantTitle = variantTitle
        self.quantity = quantity
        self.price = price
        self.total = total
        self.image = image
        self.variantID = variantID
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, presentmentTitle, variantId, quantity, price, currentTotalPrice, image
    }

    /// Decodes `presentmentTitle` as the variant title and `currentTotalPrice` as the total.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        let title = try container.decodeIfPresent(String.self, forKey: .presentmentTitle)
        variantTitle = title.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0 == "Default Title" ? nil : $0 }
        quantity = try container.decodeIfPresent(Int.self, forKey: .quantity) ?? 1
        price = try container.decodeIfPresent(MoneyV2.self, forKey: .price)
        total = try container.decodeIfPresent(MoneyV2.self, forKey: .currentTotalPrice)
        image = try container.decodeIfPresent(ShopifyImage.self, forKey: .image)
        variantID = try container.decodeIfPresent(ShopifyID.self, forKey: .variantId)
    }
}

// MARK: - OrderFulfillment

/// A fulfillment of an order (Customer Account API `Fulfillment`).
public struct OrderFulfillment: Sendable, Hashable, Decodable, Identifiable {
    /// The fulfillment GID.
    public let id: ShopifyID
    /// `SUCCESS`, `CANCELLED`, `ERROR` or `FAILURE`, if known.
    public let status: String?
    /// The latest carrier event, e.g. `DELIVERED`, for shipped goods.
    public let latestShipmentStatus: String?
    /// When the fulfillment last changed.
    public let updatedAt: Date?

    /// Creates a fulfillment.
    public init(id: ShopifyID, status: String?, latestShipmentStatus: String?, updatedAt: Date?) {
        self.id = id
        self.status = status
        self.latestShipmentStatus = latestShipmentStatus
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, status, latestShipmentStatus, updatedAt
    }

    /// Decodes the `DateTime` of `updatedAt`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ShopifyID.self, forKey: .id)
        status = try container.decodeIfPresent(String.self, forKey: .status)
        latestShipmentStatus = try container.decodeIfPresent(String.self, forKey: .latestShipmentStatus)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt).flatMap(ArticleCoding.date(from:))
    }

    /// Whether the fulfillment succeeded.
    public var isSuccessful: Bool {
        status == "SUCCESS"
    }
}
