@testable import Core
import Foundation
import Testing

@Suite("AppConfiguration")
struct AppConfigurationTests {
    // MARK: - Fixtures

    /// A complete dictionary as produced by the xcconfig files of the app.
    private static func validInfo() -> [String: Any] {
        [
            "KXShopDomain": "45dv93-bk.myshopify.com",
            "KXStoreWebDomain": "www.karinex.de",
            "KXStorefrontAPIVersion": "2026-07",
            "KXStorefrontAccessToken": "0123456789abcdef0123456789abcdef",
            "KXCustomerAccountAPIVersion": "2026-07",
            "KXCustomerAccountClientID": "shp_1234abcd-0000-4000-8000-1234567890ab",
            "CFBundleShortVersionString": "0.1.0",
            "CFBundleVersion": "7",
        ]
    }

    private static func info(setting key: String, to value: Any?) -> [String: Any] {
        var info = validInfo()
        info[key] = value
        return info
    }

    // MARK: - Valid input

    @Test("Parses a complete dictionary")
    func parsesValidDictionary() throws {
        let configuration = try AppConfiguration(infoDictionary: Self.validInfo())
        #expect(configuration.shopDomain == "45dv93-bk.myshopify.com")
        #expect(configuration.storeWebDomain == "www.karinex.de")
        #expect(configuration.storefrontAPIVersion == "2026-07")
        #expect(configuration.storefrontAccessToken == "0123456789abcdef0123456789abcdef")
        #expect(configuration.customerAccountAPIVersion == "2026-07")
        #expect(configuration.customerAccountClientID == "shp_1234abcd-0000-4000-8000-1234567890ab")
        #expect(configuration.appVersion == "0.1.0")
        #expect(configuration.buildNumber == "7")
        #expect(configuration.isStorefrontTokenConfigured)
        #expect(configuration.isCustomerAccountConfigured)
    }

    @Test("Builds the endpoint and discovery URLs")
    func derivedURLs() throws {
        let configuration = try AppConfiguration(infoDictionary: Self.validInfo())
        #expect(configuration.storefrontEndpoint.absoluteString == "https://45dv93-bk.myshopify.com/api/2026-07/graphql.json")
        #expect(configuration.storeWebURL.absoluteString == "https://www.karinex.de")
        #expect(
            configuration.customerAccountDiscoveryURL.absoluteString
                == "https://www.karinex.de/.well-known/customer-account-api"
        )
        #expect(
            configuration.openIDConfigurationURL.absoluteString
                == "https://www.karinex.de/.well-known/openid-configuration"
        )
    }

    @Test("Trims whitespace and lowercases domains")
    func normalizesValues() throws {
        var info = Self.validInfo()
        info["KXShopDomain"] = "  45DV93-BK.myshopify.com \n"
        info["KXStorefrontAPIVersion"] = " 2026-07 "
        let configuration = try AppConfiguration(infoDictionary: info)
        #expect(configuration.shopDomain == "45dv93-bk.myshopify.com")
        #expect(configuration.storefrontAPIVersion == "2026-07")
    }

    @Test("Accepts the unstable API version")
    func acceptsUnstable() throws {
        let configuration = try AppConfiguration(infoDictionary: Self.info(setting: "KXStorefrontAPIVersion", to: "unstable"))
        #expect(configuration.storefrontEndpoint.absoluteString == "https://45dv93-bk.myshopify.com/api/unstable/graphql.json")
    }

    @Test("The preview configuration matches the live store in tokenless mode")
    func previewValues() {
        let preview = AppConfiguration.preview
        #expect(preview.shopDomain == "45dv93-bk.myshopify.com")
        #expect(preview.storeWebDomain == "www.karinex.de")
        #expect(preview.storefrontAPIVersion == "2026-07")
        #expect(preview.customerAccountAPIVersion == "2026-07")
        #expect(preview.storefrontAccessToken == nil)
        #expect(!preview.isStorefrontTokenConfigured)
        #expect(preview.storefrontEndpoint.absoluteString == "https://45dv93-bk.myshopify.com/api/2026-07/graphql.json")
    }

    // MARK: - Optional keys

    @Test(
        "Empty, unresolved or absent optional values become nil",
        arguments: ["", "   ", "$(KX_STOREFRONT_ACCESS_TOKEN)", "${KX_STOREFRONT_ACCESS_TOKEN}", nil] as [String?]
    )
    func optionalValuesBecomeNil(value: String?) throws {
        var info = Self.validInfo()
        info["KXStorefrontAccessToken"] = value
        info["KXCustomerAccountClientID"] = value
        let configuration = try AppConfiguration(infoDictionary: info)
        #expect(configuration.storefrontAccessToken == nil)
        #expect(configuration.customerAccountClientID == nil)
        #expect(!configuration.isStorefrontTokenConfigured)
        #expect(!configuration.isCustomerAccountConfigured)
    }

    // MARK: - Missing required keys

    @Test(
        "Missing required keys throw missingValue",
        arguments: [
            "KXShopDomain", "KXStoreWebDomain", "KXStorefrontAPIVersion", "KXCustomerAccountAPIVersion",
            "CFBundleShortVersionString", "CFBundleVersion",
        ]
    )
    func missingRequiredKey(key: String) {
        #expect(throws: ConfigurationError.missingValue(key: key)) {
            try AppConfiguration(infoDictionary: Self.info(setting: key, to: nil))
        }
    }

    @Test("Unresolved build settings in required keys throw missingValue")
    func unresolvedRequiredKey() {
        #expect(throws: ConfigurationError.missingValue(key: "KXShopDomain")) {
            try AppConfiguration(infoDictionary: Self.info(setting: "KXShopDomain", to: "$(KX_SHOP_DOMAIN)"))
        }
        #expect(throws: ConfigurationError.missingValue(key: "KXStorefrontAPIVersion")) {
            try AppConfiguration(infoDictionary: Self.info(setting: "KXStorefrontAPIVersion", to: "  "))
        }
    }

    // MARK: - Invalid values

    @Test(
        "Rejects domains that are not bare hosts",
        arguments: [
            "https://45dv93-bk.myshopify.com", "45dv93-bk.myshopify.com/api", "shop domain.com", "localhost",
            "karinex.de:443", "-karinex.de", "karinex-.de", "karinex..de", "user@karinex.de", "192.168.0.1",
        ]
    )
    func rejectsInvalidDomain(domain: String) {
        #expect(throws: ConfigurationError.invalidValue(key: "KXShopDomain", value: domain.lowercased())) {
            try AppConfiguration(infoDictionary: Self.info(setting: "KXShopDomain", to: domain))
        }
    }

    @Test(
        "Rejects malformed API versions",
        arguments: ["2026-7", "2026-06", "26-07", "2026/07", "2026-07-01", "latest", "2026-13"]
    )
    func rejectsInvalidVersion(version: String) {
        #expect(throws: ConfigurationError.invalidValue(key: "KXCustomerAccountAPIVersion", value: version)) {
            try AppConfiguration(infoDictionary: Self.info(setting: "KXCustomerAccountAPIVersion", to: version))
        }
    }

    @Test("Rejects non-string values")
    func rejectsNonString() {
        #expect(throws: ConfigurationError.invalidValue(key: "CFBundleVersion", value: "42")) {
            try AppConfiguration(infoDictionary: Self.info(setting: "CFBundleVersion", to: 42))
        }
    }

    @Test("Validates quarterly API versions", arguments: ["2025-01", "2025-04", "2026-07", "2026-10", "unstable"])
    func acceptsQuarterlyVersions(version: String) {
        #expect(AppConfiguration.isValidAPIVersion(version))
    }

    // MARK: - Logging safety

    @Test("Descriptions never contain the token")
    func descriptionsHideSecrets() throws {
        let configuration = try AppConfiguration(infoDictionary: Self.validInfo())
        let token = "0123456789abcdef0123456789abcdef"
        #expect(!configuration.description.contains(token))
        #expect(!configuration.debugDescription.contains(token))
        #expect(!configuration.description.contains("shp_1234abcd"))
        #expect(configuration.description.contains("storefrontAccessToken: <redacted>"))

        var dumped = ""
        dump(configuration, to: &dumped)
        #expect(!dumped.contains(token))
        #expect(dumped.contains("45dv93-bk.myshopify.com"))
    }

    @Test("Configuration errors describe the key")
    func errorDescriptions() {
        #expect(ConfigurationError.missingValue(key: "KXShopDomain").description.contains("KXShopDomain"))
        #expect(ConfigurationError.invalidValue(key: "KXShopDomain", value: "x y").description.contains("x y"))
    }
}
