import Core
import Foundation
@testable import ShopifyKit
import Testing

// MARK: - MoneyV2

@Suite("MoneyV2")
struct MoneyV2Tests {
    private func decode(_ json: String) throws -> MoneyV2 {
        try JSONDecoder().decode(MoneyV2.self, from: Data(json.utf8))
    }

    @Test("Parses decimal strings exactly with a POSIX parser")
    func parsing() throws {
        #expect(try decode(#"{"amount":"29.9","currencyCode":"EUR"}"#).amount == decimal("29.90"))
        #expect(try decode(#"{"amount":"149.99","currencyCode":"EUR"}"#).amount == decimal("149.99"))
        #expect(try decode(#"{"amount":"1234567.89","currencyCode":"HUF"}"#).amount == decimal("1234567.89"))
        #expect(try decode(#"{"amount":"0.0","currencyCode":"EUR"}"#).isZero)
        #expect(try decode(#"{"amount":"-3.5","currencyCode":"EUR"}"#).amount == decimal("-3.5"))
        #expect(try decode(#"{"amount":12.5,"currencyCode":"EUR"}"#).amount == decimal("12.5"))
        #expect(try decode(#"{"amount":"29.9","currencyCode":"eur"}"#).currencyCode == .eur)
    }

    @Test("Rejects amounts that are not plain decimals", arguments: ["29,90", "abc", "1e5", "", "-", "1.", ".5", "1.2.3", "29.90 EUR"])
    func invalidAmounts(amount: String) {
        #expect(MoneyV2(amount: amount, currencyCode: .eur) == nil)
        #expect(throws: DecodingError.self) {
            try decode(#"{"amount":"\#(amount)","currencyCode":"EUR"}"#)
        }
    }

    @Test("Formats for de_DE with comma and euro sign")
    func germanFormatting() throws {
        let money = try #require(MoneyV2(amount: "29.9", currencyCode: .eur))
        let formatted = money.formatted(locale: Locale(identifier: "de_DE"))
        #expect(formatted.contains("29,90"))
        #expect(formatted.contains("€"))
        let compareAt = try #require(MoneyV2(amount: "149.99", currencyCode: .eur))
        #expect(compareAt.formatted(locale: Locale(identifier: "de_DE")).contains("149,99"))
    }

    @Test("Formats CHF for de_CH and fr_CH", arguments: ["de_CH", "fr_CH"])
    func swissFormatting(locale: String) throws {
        let money = try #require(MoneyV2(amount: "29.0", currencyCode: .chf))
        let formatted = money.formatted(locale: Locale(identifier: locale))
        #expect(formatted.contains("29"))
        #expect(formatted.contains("CHF"))
    }

    @Test("Encodes the amount as a POSIX string and round trips")
    func encoding() throws {
        let money = MoneyV2(amount: decimal("12.9"), currencyCode: .eur)
        let json = try String(decoding: JSONEncoder().encode(money), as: UTF8.self)
        #expect(json.contains(#""amount":"12.9""#))
        #expect(try JSONDecoder().decode(MoneyV2.self, from: Data(json.utf8)) == money)
        #expect(money.description == "12.9 EUR")
    }
}

// MARK: - ShopifyImage

@Suite("ShopifyImage")
struct ShopifyImageTests {
    private func image(_ string: String) throws -> ShopifyImage {
        try ShopifyImage(url: #require(URL(string: string)), altText: nil, width: 2048, height: 1024)
    }

    @Test("Adds a width and keeps the cache buster")
    func addsWidth() throws {
        let original = "https://cdn.shopify.com/s/files/1/0917/5328/3851/files/Office_2024_Professional_Plus.webp?v=1787443066"
        let url = try image(original).url(width: 600)
        #expect(url.absoluteString == original + "&width=600")
    }

    @Test("Replaces an existing width and preserves other items exactly")
    func replacesWidth() throws {
        let url = try image("https://cdn.shopify.com/a.webp?width=100&v=1&name=a%20b").url(width: 300)
        #expect(url.absoluteString == "https://cdn.shopify.com/a.webp?v=1&name=a%20b&width=300")
    }

    @Test("Works without a query and clamps widths below 1")
    func edgeCases() throws {
        #expect(try image("https://cdn.shopify.com/a.webp").url(width: 0).absoluteString == "https://cdn.shopify.com/a.webp?width=1")
        #expect(try image("https://cdn.shopify.com/a.webp").url(width: 750).absoluteString == "https://cdn.shopify.com/a.webp?width=750")
    }

    @Test("Accept header switches the CDN to WebP; aspect ratio")
    func acceptHeaderAndAspectRatio() throws {
        #expect(ShopifyImage.acceptHeader == "image/webp,image/*;q=0.8")
        #expect(try image("https://cdn.shopify.com/a.webp").aspectRatio == 2)
        #expect(try ShopifyImage(url: #require(URL(string: "https://cdn.shopify.com/a.webp"))).aspectRatio == nil)
    }
}

// MARK: - ShopifyID

@Suite("ShopifyID")
struct ShopifyIDTests {
    @Test("Resource type and ID")
    func components() {
        let product: ShopifyID = "gid://shopify/Product/10534352027915"
        #expect(product.resourceType == "Product")
        #expect(product.resourceID == "10534352027915")
        #expect(product.isShopifyGID)

        let cart = ShopifyID("gid://shopify/Cart/c1-abc?key=def")
        #expect(cart.resourceType == "Cart")
        #expect(cart.resourceID == "c1-abc")

        let invalid = ShopifyID(rawValue: "product-123")
        #expect(invalid.resourceType == nil)
        #expect(invalid.resourceID == nil)
        #expect(!invalid.isShopifyGID)
        #expect(ShopifyID("gid://shopify/Product/").resourceType == nil)
    }

    @Test("Codes as a plain string")
    func codable() throws {
        let id: ShopifyID = "gid://shopify/ProductVariant/52710041846027"
        let data = try JSONEncoder().encode([id])
        #expect(String(decoding: data, as: UTF8.self) == #"["gid:\/\/shopify\/ProductVariant\/52710041846027"]"#
            || String(decoding: data, as: UTF8.self) == #"["gid://shopify/ProductVariant/52710041846027"]"#)
        #expect(try JSONDecoder().decode([ShopifyID].self, from: data) == [id])
    }
}

// MARK: - Codes

@Suite("Country, language and currency codes")
struct CodeTests {
    @Test("Normalization")
    func normalization() {
        #expect(CountryCode(rawValue: " de ") == .de)
        #expect(LanguageCode(rawValue: "pt-pt") == .ptPT)
        #expect(CurrencyCode(rawValue: "chf") == .chf)
        #expect(CountryCode.de.description == "DE")
        #expect(CountryCode.recordedStoreCountries.count == 28)
        #expect(LanguageCode.recordedStoreLanguages.count == 13)
    }

    @Test("Every app language maps to a store language and back", arguments: AppLanguage.allCases)
    func appLanguageRoundTrip(language: AppLanguage) {
        let code = LanguageCode(appLanguage: language)
        #expect(code.appLanguage == language)
        #expect(LanguageCode.recordedStoreLanguages.contains(code))
    }

    @Test("Specific mappings")
    func mappings() {
        #expect(LanguageCode(appLanguage: .ptPT).rawValue == "PT_PT")
        #expect(LanguageCode(appLanguage: .de).rawValue == "DE")
        #expect(LanguageCode.el.appLanguage == nil)
        #expect(LanguageCode.ro.appLanguage == nil)
        #expect(LanguageCode(rawValue: "PT").appLanguage == .ptPT)
        #expect(LanguageCode(rawValue: "PT_BR").appLanguage == .ptPT)
    }

    @Test("Codes decode and encode as strings")
    func codable() throws {
        let decoded = try JSONDecoder().decode([String: CountryCode].self, from: Data(#"{"c":"ch"}"#.utf8))
        #expect(decoded["c"] == .ch)
        #expect(try String(decoding: JSONEncoder().encode(LanguageCode.ptPT), as: UTF8.self) == #""PT_PT""#)
    }

    @Test("User error codes decode known and unknown values")
    func userErrorCodes() throws {
        let json = #"["INVALID","LESS_THAN","MERCHANDISE_OUT_OF_STOCK","NEW_CODE"]"#
        let codes = try JSONDecoder().decode([UserErrorCode].self, from: Data(json.utf8))
        #expect(codes == [.invalid, .lessThan, .merchandiseOutOfStock, .unknown("NEW_CODE")])
        #expect(codes.map(\.rawValue) == ["INVALID", "LESS_THAN", "MERCHANDISE_OUT_OF_STOCK", "NEW_CODE"])
        #expect(UserErrorCode(rawValue: "MAXIMUM_EXCEEDED") == .maximumExceeded)
        #expect(UserErrorCode(rawValue: "INVALID_DELIVERY_GROUP") == .invalidDeliveryGroup)
        #expect(UserErrorCode(rawValue: "MISSING_DISCOUNT_CODE") == .missingDiscountCode)
        let encoded = try JSONEncoder().encode(UserErrorCode.invalidMerchandiseLine)
        #expect(String(decoding: encoded, as: UTF8.self) == #""INVALID_MERCHANDISE_LINE""#)
    }

    @Test("Cart line quantities are at least 1")
    func cartLineQuantity() {
        #expect(CartLineInput(merchandiseId: "gid://shopify/ProductVariant/1", quantity: 0).quantity == 1)
        #expect(CartLineInput(merchandiseId: "gid://shopify/ProductVariant/1", quantity: 3).quantity == 3)
    }

    @Test("Collection page size is clamped to 1...250")
    func pageSize() {
        #expect(CollectionProductsQuery(handle: "a", first: 0).variables.first == 1)
        #expect(CollectionProductsQuery(handle: "a", first: 1000).variables.first == 250)
        #expect(CollectionProductsQuery(handle: "a", first: 24).variables.first == 24)
    }
}
