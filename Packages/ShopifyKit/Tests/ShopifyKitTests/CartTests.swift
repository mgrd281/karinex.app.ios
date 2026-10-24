import Core
import Foundation
@testable import ShopifyKit
import Testing

/// The recorded cart lifecycle (2026-10-24, DE/DE, tokens replaced with `REDACTED`) decoded
/// through the real client, and the cart repository against a stub transport.
@Suite("Cart")
struct CartTests {
    private static let office2019Variant: ShopifyID = "gid://shopify/ProductVariant/52555874009355"
    private static let windows10Variant: ShopifyID = "gid://shopify/ProductVariant/52711848345867"
    private static let redactedCartID: ShopifyID = "gid://shopify/Cart/REDACTED?key=REDACTED"

    private func eur(_ amount: String) -> MoneyV2 {
        MoneyV2(amount: decimal(amount), currencyCode: .eur)
    }

    private func repository(_ stub: StubHTTPClient) -> StorefrontCartRepository {
        StorefrontCartRepository(
            client: makeStorefrontClient(stub),
            contextProvider: StaticStorefrontContextProvider(context: germanyContext)
        )
    }

    // MARK: - Recorded lifecycle

    @Test("cartCreate: one digital line with the full CartFields, attributes and buyer country")
    func created() throws {
        let payload = try #require(try Fixture.decode(CartCreateMutation.ResponseData.self, from: Fixture.cartCreate).payload)
        let cart = try #require(payload.cart)

        #expect(payload.userErrors.isEmpty)
        #expect(payload.warnings.isEmpty)
        #expect(cart.id == Self.redactedCartID)
        #expect(cart.checkoutUrl.absoluteString == "https://www.karinex.de/cart/c/REDACTED?key=REDACTED&_cs=REDACTED")
        #expect(cart.totalQuantity == 1)
        #expect(cart.buyerIdentity == CartBuyerIdentity(countryCode: .de, email: nil))
        #expect(cart.attributes == FixturePlanValues.cartAttributes)
        #expect(cart.attribute("app_platform") == "ios")
        #expect(cart.discountCodes.isEmpty)
        #expect(cart.discountApplications.isEmpty)
        #expect(cart.note?.isEmpty == true)
        #expect(cart.cost == CartCost(
            subtotalAmount: eur("9.9"),
            totalAmount: eur("9.9"),
            totalTaxAmount: nil,
            checkoutChargeAmount: eur("9.9")
        ))
        #expect(cart.discountTotal == nil)
        #expect(!cart.requiresShipping)
        #expect(!cart.isEmpty)

        let line = try #require(cart.lines.first)
        #expect(line.id.resourceType == "CartLine")
        #expect(line.id.rawValue.hasSuffix("?cart=REDACTED"))
        #expect(line.quantity == 1)
        #expect(line.discountAllocations.isEmpty)
        #expect(line.cost == CartLineCost(
            amountPerQuantity: eur("9.9"),
            compareAtAmountPerQuantity: eur("29.9"),
            subtotalAmount: eur("9.9"),
            totalAmount: eur("9.9")
        ))
        let merchandise = line.merchandise
        #expect(merchandise.id == Self.office2019Variant)
        #expect(merchandise.title == "Default Title")
        #expect(merchandise.sku == "0889842335830")
        #expect(!merchandise.requiresShipping)
        #expect(merchandise.availableForSale)
        #expect(merchandise.price == eur("9.9"))
        #expect(merchandise.compareAtPrice == eur("29.9"))
        #expect(merchandise.image?.url.host == "cdn.shopify.com")
        #expect(merchandise.selectedOptions == [SelectedOption(name: "Title", value: "Default Title")])
        #expect(merchandise.visibleOptions.isEmpty)
        #expect(merchandise.product.handle == "microsoft-office-2019-professional-plus-windows")
        #expect(merchandise.product.vendor == "Microsoft")
        #expect(merchandise.product.id.resourceType == "Product")
        #expect(cart.line(id: line.id) == line)
    }

    @Test("cartLinesAdd: two lines and the store's automatic 10 % quantity discount as a cart discount application")
    func linesAdded() throws {
        let cart = try #require(try Fixture.decode(CartLinesAddMutation.ResponseData.self, from: Fixture.cartLinesAdd).payload?.cart)

        #expect(cart.totalQuantity == 2)
        #expect(Set(cart.lines.map(\.merchandise.id)) == [Self.office2019Variant, Self.windows10Variant])
        #expect(cart.cost.subtotalAmount == eur("19.8"))
        #expect(cart.cost.totalAmount == eur("17.82"))
        #expect(cart.discountTotal == eur("1.98"))

        let discount = try #require(cart.discountApplications.first)
        #expect(cart.discountApplications.count == 1)
        #expect(discount.source == .automatic(title: "Mengenrabatt: ab 2 Lizenzen -10%"))
        #expect(discount.title == "Mengenrabatt: ab 2 Lizenzen -10%")
        #expect(discount.value == .percentage(10))
        #expect(discount.totalAllocatedAmount == eur("1.98"))
        #expect(discount.targetType == "LINE_ITEM")
        #expect(discount.allocationMethod == "ACROSS")
        let lineDiscounts = cart.lines.flatMap(\.discountAllocations)
        #expect(lineDiscounts.isEmpty)
    }

    @Test("cartLinesUpdate: quantity 2 on the first line, 15 % from three licenses")
    func linesUpdated() throws {
        let cart = try #require(try Fixture.decode(CartLinesUpdateMutation.ResponseData.self, from: Fixture.cartLinesUpdate).payload?.cart)

        #expect(cart.totalQuantity == 3)
        let office = try #require(cart.lines.first { $0.merchandise.id == Self.office2019Variant })
        #expect(office.quantity == 2)
        #expect(office.cost.subtotalAmount == eur("19.8"))
        #expect(office.cost.amountPerQuantity == eur("9.9"))
        #expect(cart.cost.totalAmount == eur("25.25"))
        #expect(cart.discountTotal == eur("4.45"))
        #expect(cart.discountApplications.first?.value == .percentage(15))
    }

    @Test("cartDiscountCodesUpdate with an unknown code: not applicable, DISCOUNT_NOT_FOUND warning")
    func invalidDiscountCode() throws {
        let payload = try #require(try Fixture.decode(
            CartDiscountCodesUpdateMutation.ResponseData.self,
            from: Fixture.cartDiscountCodesInvalid
        ).payload)
        let cart = try #require(payload.cart)

        #expect(payload.userErrors.isEmpty)
        #expect(cart.discountCodes == [CartDiscountCode(code: "KX-FIXTURE-NOT-A-CODE", applicable: false)])
        let warning = try #require(payload.warnings.first)
        #expect(payload.warnings.count == 1)
        #expect(warning.code == "DISCOUNT_NOT_FOUND")
        #expect(warning.isDiscountWarning)
        #expect(warning.message == "Gib einen gültigen Rabattcode ein")
        #expect(warning.target == "gid://shopify/Cart/REDACTED")
        #expect(cart.discountApplications.map(\.title) == ["Mengenrabatt: ab 3 Lizenzen -15%"])
    }

    @Test("cartLinesRemove and the final cart query: one line, quantity 2")
    func removedAndQueried() throws {
        let removed = try #require(try Fixture.decode(CartLinesRemoveMutation.ResponseData.self, from: Fixture.cartLinesRemove).payload?
            .cart)
        #expect(removed.lines.map(\.merchandise.id) == [Self.office2019Variant])
        #expect(removed.totalQuantity == 2)

        let queried = try #require(try Fixture.decode(CartQuery.ResponseData.self, from: Fixture.cartQuery).cart)
        #expect(queried == removed)
        #expect(queried.discountCodes.first?.applicable == false)
        #expect(queried.cost.totalAmount == eur("17.82"))
    }

    @Test("Carts encode back into the shape they decode from")
    func roundTrip() throws {
        let carts = try [
            #require(try Fixture.decode(CartCreateMutation.ResponseData.self, from: Fixture.cartCreate).payload?.cart),
            #require(try Fixture.decode(CartLinesAddMutation.ResponseData.self, from: Fixture.cartLinesAdd).payload?.cart),
            #require(try Fixture.decode(CartDiscountCodesUpdateMutation.ResponseData.self, from: Fixture.cartDiscountCodesInvalid).payload?
                .cart),
        ]
        for cart in carts {
            #expect(try JSONDecoder().decode(Cart.self, from: JSONEncoder().encode(cart)) == cart)
        }
    }

    // MARK: - Repository

    @Test("cart(id:) sends the ID and returns the cart; null means expired or completed")
    func cartQuery() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.cartQuery), .json(#"{"data":{"cart":null}}"#)])
        let repository = repository(stub)

        let cart = try #require(try await repository.cart(id: Self.redactedCartID))
        #expect(cart.totalQuantity == 2)
        #expect(try await repository.cart(id: "gid://shopify/Cart/expired?key=k") == nil)

        let body = try SentGraphQLBody(stub.requests[0])
        #expect(body.operationName == "Cart")
        #expect(body.variables["id"] == .string(Self.redactedCartID.rawValue))
        #expect(body.query.hasPrefix("query Cart($id: ID!) @inContext(country: DE, language: DE,"))
    }

    @Test("createCart sends lines, the context's country and the attributes")
    func createCart() async throws {
        let stub = try StubHTTPClient([.fixture(Fixture.cartCreate)])
        let result = try await repository(stub).createCart(
            lines: [CartLineInput(merchandiseId: Self.office2019Variant, quantity: 1)],
            attributes: [AttributeInput(key: "app_platform", value: "ios"), AttributeInput(key: "app_version", value: "1.0")]
        )
        #expect(result.cart.lines.count == 1)

        let body = try SentGraphQLBody(#require(stub.requests.first))
        #expect(body.operationName == "CartCreate")
        let expected: JSONAny = .object([
            "lines": .array([.object(["merchandiseId": .string(Self.office2019Variant.rawValue), "quantity": .number(1)])]),
            "buyerIdentity": .object(["countryCode": .string("DE")]),
            "attributes": .array([
                .object(["key": .string("app_platform"), "value": .string("ios")]),
                .object(["key": .string("app_version"), "value": .string("1.0")]),
            ]),
        ])
        #expect(body.variables["input"] == expected)
    }

    @Test("Line mutations send the cart ID and their inputs")
    func lineMutations() async throws {
        let stub = try StubHTTPClient([
            .fixture(Fixture.cartLinesAdd),
            .fixture(Fixture.cartLinesUpdate),
            .fixture(Fixture.cartLinesRemove),
        ])
        let repository = repository(stub)
        let lineID: ShopifyID = "gid://shopify/CartLine/line-1?cart=REDACTED"

        let added = try await repository.addLines(cartID: Self.redactedCartID, lines: [CartLineInput(merchandiseId: Self.windows10Variant)])
        #expect(added.cart.lines.count == 2)
        let updated = try await repository.updateLines(cartID: Self.redactedCartID, lines: [CartLineUpdateInput(id: lineID, quantity: 2)])
        #expect(updated.cart.totalQuantity == 3)
        let removed = try await repository.removeLines(cartID: Self.redactedCartID, lineIDs: [lineID])
        #expect(removed.cart.lines.count == 1)
        #expect(removed.warnings.map(\.code) == ["DISCOUNT_NOT_FOUND"])

        let bodies = try stub.requests.map(SentGraphQLBody.init)
        #expect(bodies.map(\.operationName) == ["CartLinesAdd", "CartLinesUpdate", "CartLinesRemove"])
        #expect(bodies.allSatisfy { $0.variables["cartId"] == .string(Self.redactedCartID.rawValue) })
        let addedLine: JSONAny = .object(["merchandiseId": .string(Self.windows10Variant.rawValue), "quantity": .number(1)])
        #expect(bodies[0].variables["lines"] == .array([addedLine]))
        #expect(bodies[1].variables["lines"] == .array([.object(["id": .string(lineID.rawValue), "quantity": .number(2)])]))
        #expect(bodies[2].variables["lineIds"] == .array([.string(lineID.rawValue)]))
    }

    @Test("Discount codes, buyer identity and attributes send their inputs and return the warnings")
    func otherMutations() async throws {
        let stub = try StubHTTPClient([
            .fixture(Fixture.cartDiscountCodesInvalid),
            Fixture.cartPayloadReply(field: "cartBuyerIdentityUpdate"),
            Fixture.cartPayloadReply(field: "cartAttributesUpdate"),
        ])
        let repository = repository(stub)

        let discounted = try await repository.updateDiscountCodes(
            cartID: Self.redactedCartID,
            codes: [" KX-FIXTURE-NOT-A-CODE ", "kx-fixture-not-a-code", ""]
        )
        #expect(discounted.warnings.first?.code == "DISCOUNT_NOT_FOUND")
        let identity = try await repository.updateBuyerIdentity(cartID: Self.redactedCartID, countryCode: .ch)
        #expect(identity.cart.totalQuantity == 2)
        let attributes = try await repository.updateAttributes(
            cartID: Self.redactedCartID,
            attributes: [AttributeInput(key: "app_platform", value: "ios")]
        )
        #expect(attributes.warnings.isEmpty)

        let bodies = try stub.requests.map(SentGraphQLBody.init)
        #expect(bodies.map(\.operationName) == ["CartDiscountCodesUpdate", "CartBuyerIdentityUpdate", "CartAttributesUpdate"])
        #expect(bodies[0].variables["discountCodes"] == .array([.string("KX-FIXTURE-NOT-A-CODE")]))
        #expect(bodies[1].variables["buyerIdentity"] == .object(["countryCode": .string("CH")]))
        #expect(bodies[2].variables["attributes"] == .array([.object(["key": .string("app_platform"), "value": .string("ios")])]))
    }

    @Test("User errors throw ShopifyError.userErrors; a missing payload or cart is a decoding error")
    func failures() async throws {
        let userErrors = #"{"data":{"cartLinesUpdate":{"cart":null,"userErrors":[{"field":["lines","0","quantity"],"#
            + #""message":"m","code":"MAXIMUM_EXCEEDED"}],"warnings":[]}}}"#
        let stub = StubHTTPClient([
            .json(userErrors),
            .json(#"{"data":{"cartLinesRemove":null}}"#),
            .json(#"{"data":{"cartAttributesUpdate":{"cart":null,"userErrors":[],"warnings":[]}}}"#),
        ])
        let repository = repository(stub)

        let quantityError = UserError(field: ["lines", "0", "quantity"], message: "m", code: .maximumExceeded)
        await #expect(throws: ShopifyError.userErrors([quantityError])) {
            _ = try await repository.updateLines(
                cartID: Self.redactedCartID,
                lines: [CartLineUpdateInput(id: "gid://shopify/CartLine/1", quantity: 99)]
            )
        }
        await #expect(throws: ShopifyError.decoding("CartLinesRemove: payload")) {
            _ = try await repository.removeLines(cartID: Self.redactedCartID, lineIDs: ["gid://shopify/CartLine/1"])
        }
        await #expect(throws: ShopifyError.decoding("CartAttributesUpdate: cart")) {
            _ = try await repository.updateAttributes(cartID: Self.redactedCartID, attributes: [])
        }
    }

    @Test("A cart mutation that may have reached Shopify is never sent twice")
    func mutationsAreNotRetried() async throws {
        let stub = try StubHTTPClient([.failure(.timeout), .fixture(Fixture.cartLinesAdd)])
        await #expect(throws: ShopifyError.network(.timeout)) {
            _ = try await repository(stub).addLines(
                cartID: Self.redactedCartID,
                lines: [CartLineInput(merchandiseId: Self.windows10Variant)]
            )
        }
        #expect(stub.requests.count == 1)
    }

    // MARK: - Inputs and derived values

    @Test("Inputs clamp and clean their values")
    func inputs() {
        #expect(CartLineUpdateInput(id: "gid://shopify/CartLine/1", quantity: -3).quantity == 0)
        #expect(CartLineUpdateInput(id: "gid://shopify/CartLine/1", quantity: 4).quantity == 4)
        let codes = CartDiscountCodesUpdateMutation(cartID: Self.redactedCartID, codes: ["  SUMMER ", "summer", "", "WINTER"])
        #expect(codes.variables.discountCodes == ["SUMMER", "WINTER"])
        #expect(CartDiscountCodesUpdateMutation(cartID: Self.redactedCartID, codes: []).variables.discountCodes.isEmpty)
        let identity = CartBuyerIdentityUpdateMutation(cartID: Self.redactedCartID, countryCode: .at)
        #expect(identity.variables.buyerIdentity == CartBuyerIdentityInput(countryCode: .at))
    }

    @Test("discountTotal needs a positive difference in one currency; requiresShipping looks at every line")
    func derivedValues() {
        let product = CartProductReference(id: "gid://shopify/Product/1", handle: "p", title: "P", vendor: "V")
        func line(requiresShipping: Bool) -> CartLine {
            CartLine(
                id: ShopifyID("gid://shopify/CartLine/\(requiresShipping)"),
                quantity: 1,
                merchandise: CartMerchandise(
                    id: "gid://shopify/ProductVariant/1",
                    title: "Default Title",
                    requiresShipping: requiresShipping,
                    availableForSale: true,
                    image: nil,
                    price: eur("10"),
                    compareAtPrice: nil,
                    product: product
                ),
                cost: CartLineCost(amountPerQuantity: eur("10"), subtotalAmount: eur("10"), totalAmount: eur("10"))
            )
        }
        func cart(subtotal: MoneyV2, total: MoneyV2, lines: [CartLine] = []) -> Cart {
            Cart(
                id: Self.redactedCartID,
                checkoutUrl: URL(fileURLWithPath: "/"),
                totalQuantity: lines.count,
                lines: lines,
                cost: CartCost(subtotalAmount: subtotal, totalAmount: total),
                discountCodes: [],
                buyerIdentity: CartBuyerIdentity(countryCode: .de, email: nil),
                attributes: []
            )
        }

        #expect(cart(subtotal: eur("10"), total: eur("10")).discountTotal == nil)
        #expect(cart(subtotal: eur("10"), total: eur("12")).discountTotal == nil)
        #expect(cart(subtotal: eur("10"), total: MoneyV2(amount: 5, currencyCode: .chf)).discountTotal == nil)
        #expect(cart(subtotal: eur("10"), total: eur("7.5")).discountTotal == eur("2.5"))
        #expect(cart(subtotal: eur("10"), total: eur("10")).isEmpty)
        #expect(!cart(subtotal: eur("10"), total: eur("10"), lines: [line(requiresShipping: false)]).requiresShipping)
        #expect(cart(subtotal: eur("10"), total: eur("10"), lines: [line(requiresShipping: false), line(requiresShipping: true)])
            .requiresShipping)
    }

    @Test("Discount applications decode money values and code and custom sources")
    func discountApplicationKinds() throws {
        let json = """
            [{"__typename":"CartCodeDiscountApplication","code":"WELCOME","targetType":"LINE_ITEM","allocationMethod":"ACROSS",
            "totalAllocatedAmount":{"amount":"5.0","currencyCode":"EUR"},
            "value":{"__typename":"MoneyV2","amount":"5.0","currencyCode":"EUR"}},
            {"__typename":"CartCustomDiscountApplication","title":"App","targetType":"SHIPPING_LINE","allocationMethod":"EACH",
            "totalAllocatedAmount":{"amount":"1.0","currencyCode":"EUR"},
            "value":{"__typename":"PricingPercentageValue","percentage":12.5}}]
            """
        let applications = try JSONDecoder().decode([CartDiscountApplication].self, from: Data(json.utf8))
        #expect(applications[0].source == .code("WELCOME"))
        #expect(applications[0].value == .money(eur("5")))
        #expect(applications[0].title == "WELCOME")
        #expect(applications[1].source == .custom(title: "App"))
        #expect(applications[1].value == .percentage(12.5))
        #expect(try JSONDecoder().decode([CartDiscountApplication].self, from: JSONEncoder().encode(applications)) == applications)
    }
}

/// Values the fixture recorder used for the lifecycle cart (see `Tools/FixtureRecorder`).
enum FixturePlanValues {
    static let cartAttributes = [
        AttributeInput(key: "app_platform", value: "ios"),
        AttributeInput(key: "kx_fixture_recording", value: "true"),
    ]
}

extension Fixture {
    /// The recorded cart (from the final cart query) as the payload of the mutation `field`,
    /// for repository tests of mutations the recorder does not send to the live store.
    static func cartPayloadReply(field: String) throws -> StubHTTPClient.Reply {
        let root = try JSONSerialization.jsonObject(with: data(cartQuery)) as? [String: Any]
        let cart = (root?["data"] as? [String: Any])?["cart"] ?? NSNull()
        let body: [String: Any] = ["data": [field: ["cart": cart, "userErrors": [Any](), "warnings": [Any]()]]]
        return try .response(HTTPResponse(statusCode: 200, headers: [:], body: JSONSerialization.data(withJSONObject: body)))
    }
}
