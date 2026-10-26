import Foundation

// MARK: - CardBrand

/// A card brand the store accepts (Storefront `CardBrand`).
public enum CardBrand: String, Sendable, Hashable, Codable, CaseIterable {
    /// Visa.
    case visa = "VISA"
    /// Mastercard.
    case mastercard = "MASTERCARD"
    /// American Express.
    case americanExpress = "AMERICAN_EXPRESS"
    /// Discover.
    case discover = "DISCOVER"
    /// Diners Club.
    case dinersClub = "DINERS_CLUB"
    /// JCB.
    case jcb = "JCB"
}

// MARK: - DigitalWallet

/// A digital wallet the store supports (Storefront `DigitalWallet`).
public enum DigitalWallet: String, Sendable, Hashable, Codable, CaseIterable {
    /// Apple Pay.
    case applePay = "APPLE_PAY"
    /// Android Pay.
    case androidPay = "ANDROID_PAY"
    /// Google Pay.
    case googlePay = "GOOGLE_PAY"
    /// Shop Pay.
    case shopifyPay = "SHOPIFY_PAY"
}

// MARK: - PaymentSettings

/// The payment methods Shopify reports for the store in the current buyer context (Storefront
/// `shop.paymentSettings`): the accepted card brands and the supported digital wallets, in
/// Shopify's order. Payment providers such as Klarna are not part of it.
public struct PaymentSettings: Sendable, Hashable, Codable {
    /// The accepted card brands.
    public let acceptedCardBrands: [CardBrand]
    /// The supported digital wallets.
    public let supportedDigitalWallets: [DigitalWallet]

    /// Creates the settings.
    public init(acceptedCardBrands: [CardBrand], supportedDigitalWallets: [DigitalWallet]) {
        self.acceptedCardBrands = acceptedCardBrands
        self.supportedDigitalWallets = supportedDigitalWallets
    }

    /// No card brands and no wallets, for catalogs without payment data.
    public static let empty = PaymentSettings(acceptedCardBrands: [], supportedDigitalWallets: [])

    private enum CodingKeys: String, CodingKey {
        case acceptedCardBrands, supportedDigitalWallets
    }

    /// Decodes both lists, dropping repeats and values this version does not know, so a new
    /// card brand or wallet on Shopify's side never fails the request.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        acceptedCardBrands = try Self.known(container.decodeIfPresent([String].self, forKey: .acceptedCardBrands) ?? [])
        supportedDigitalWallets = try Self.known(container.decodeIfPresent([String].self, forKey: .supportedDigitalWallets) ?? [])
    }

    private static func known<Value: RawRepresentable>(_ rawValues: [String]) -> [Value] where Value.RawValue == String {
        var seen: Set<String> = []
        return rawValues.compactMap { seen.insert($0).inserted ? Value(rawValue: $0) : nil }
    }
}

// MARK: - PaymentSettingsQuery

/// Loads the store's payment settings (Storefront `shop.paymentSettings`).
public struct PaymentSettingsQuery: GraphQLOperation {
    /// The `data` of the response.
    public struct ResponseData: Decodable, Sendable, Equatable {
        /// The shop with its payment settings.
        public struct Shop: Decodable, Sendable, Equatable {
            /// The payment settings.
            public let paymentSettings: PaymentSettings
        }

        /// The shop.
        public let shop: Shop
    }

    /// `PaymentSettings`.
    public static let operationName = "PaymentSettings"
    /// A query.
    public static let kind = GraphQLOperationKind.query
    /// The operation.
    public static let document = """
        query PaymentSettings {
          shop {
            paymentSettings {
              acceptedCardBrands
              supportedDigitalWallets
            }
          }
        }

        """

    /// Creates the query.
    public init() {}
}
