import Core
import Foundation
@testable import ShopifyKit
import Testing

/// `shop.paymentSettings`: the accepted card brands and digital wallets.
@Suite("Payment settings")
struct PaymentSettingsTests {
    @Test("Known brands and wallets are kept in Shopify's order; unknown values and repeats are dropped")
    func decoding() throws {
        let json = #"""
            {"acceptedCardBrands":["VISA","MASTERCARD","UNION_PAY","VISA","AMERICAN_EXPRESS"],
             "supportedDigitalWallets":["APPLE_PAY","SHOPIFY_PAY","SAMSUNG_PAY"]}
            """#
        let settings = try JSONDecoder().decode(PaymentSettings.self, from: Data(json.utf8))
        #expect(settings.acceptedCardBrands == [.visa, .mastercard, .americanExpress])
        #expect(settings.supportedDigitalWallets == [.applePay, .shopifyPay])
        #expect(try JSONDecoder().decode(PaymentSettings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test("Missing lists decode as empty")
    func missingLists() throws {
        let settings = try JSONDecoder().decode(PaymentSettings.self, from: Data("{}".utf8))
        #expect(settings == .empty)
    }

    @Test("The repository sends the query in the buyer context and returns the settings")
    func repository() async throws {
        let body: [String: Any] = [
            "data": [
                "shop": [
                    "paymentSettings": [
                        "acceptedCardBrands": ["VISA", "MASTERCARD"],
                        "supportedDigitalWallets": ["APPLE_PAY"],
                    ],
                ],
            ],
        ]
        let reply = try StubHTTPClient.Reply.response(
            HTTPResponse(statusCode: 200, headers: [:], body: JSONSerialization.data(withJSONObject: body))
        )
        let stub = StubHTTPClient([reply])
        let repository = StorefrontCatalogRepository(
            client: makeStorefrontClient(stub),
            contextProvider: StaticStorefrontContextProvider(context: germanyContext)
        )

        let settings = try await repository.paymentSettings()

        #expect(settings.acceptedCardBrands == [.visa, .mastercard])
        #expect(settings.supportedDigitalWallets == [.applePay])
        let sent = try SentGraphQLBody(#require(stub.requests.first))
        #expect(sent.operationName == PaymentSettingsQuery.operationName)
        #expect(sent.query.contains("paymentSettings {"))
        #expect(sent.query.contains("@inContext(country: DE, language: DE"))
    }
}
