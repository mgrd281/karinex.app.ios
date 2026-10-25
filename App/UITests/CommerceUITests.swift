import XCTest

// MARK: - CommerceUITests

/// Critical-path UI tests of the commerce core against the live store (tokenless Storefront
/// API): products on Start, product detail, adding to the cart, the cart badge, the cart and
/// Shopify checkout, search and deep links.
///
/// The app runs with `-kx.uitesting` (fixed online network status, no market sheet),
/// `-kx.reset` (empty cart, no state from earlier runs) and German language and region. The
/// store answers over the network, so the timeouts are generous. The checkout is only opened
/// and closed again; no order is placed, and the test cart expires on its own.
final class CommerceUITests: XCTestCase {
    /// How long store content may take to arrive.
    private let networkTimeout: TimeInterval = 30
    /// How long local UI changes may take.
    private let timeout: TimeInterval = 10

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Tests

    @MainActor
    func testStartShowsProductRows() {
        let app = launchApp()

        XCTAssertTrue(element("screen.home", in: app).waitForExistence(timeout: timeout), "Start is not the initial tab")
        XCTAssertTrue(
            productCard(in: app).waitForExistence(timeout: networkTimeout),
            "No product row appeared on Start"
        )
    }

    @MainActor
    func testAddToCartAndOpenCheckout() {
        let app = launchApp()

        // Open the first product of the first live row on Start.
        let card = productCard(in: app)
        XCTAssertTrue(card.waitForExistence(timeout: networkTimeout), "No product row appeared on Start")
        scrollIntoView(card, in: app)
        card.tap()
        XCTAssertTrue(element("screen.product", in: app).waitForExistence(timeout: networkTimeout), "The product did not open")

        // Add it to the cart.
        let addToCart = app.buttons["product.addToCart"]
        XCTAssertTrue(addToCart.waitForExistence(timeout: networkTimeout), "The purchase bar did not appear")
        XCTAssertTrue(waitUntil(addToCart, matches: "isEnabled == true", timeout: networkTimeout), "The product cannot be added")
        addToCart.tap()

        // The Warenkorb tab shows one item.
        let cartTab = tabButton(identifier: "tab.cart", germanTitle: "Warenkorb", in: app)
        XCTAssertTrue(cartTab.waitForExistence(timeout: timeout))
        XCTAssertTrue(
            waitUntil(cartTab, matches: "value CONTAINS '1'", timeout: networkTimeout),
            "The cart badge does not show 1 (value: \(String(describing: cartTab.value)))"
        )

        // The cart lists the line.
        cartTab.tap()
        XCTAssertTrue(element("screen.cart", in: app).waitForExistence(timeout: timeout), "The cart did not open")
        // SwiftUI exposes the lines card (`cart.lines`) but not each row as its own container,
        // so a line is recognized by its remove button inside the card.
        let lines = element("cart.lines", in: app)
        let line = lines.buttons["cart.remove"].firstMatch
        XCTAssertTrue(
            line.waitForExistence(timeout: networkTimeout),
            "The cart shows no line. Hierarchy: \(Self.singleLine(app.debugDescription))"
        )
        XCTAssertTrue(element("cart.total", in: app).exists, "The cart shows no total")

        // "Zur Kasse" opens Shopify checkout in a sheet.
        let checkout = app.buttons["cart.checkout"]
        XCTAssertTrue(checkout.waitForExistence(timeout: timeout), "\"Zur Kasse\" is missing")
        checkout.tap()
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: networkTimeout), "The checkout sheet did not appear")

        // Closing the checkout keeps the cart.
        closeCheckout(in: app)
        XCTAssertTrue(webView.waitForNonExistence(timeout: networkTimeout), "The checkout sheet did not close")
        XCTAssertTrue(element("screen.cart", in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(line.waitForExistence(timeout: timeout), "Cancelling the checkout emptied the cart")
    }

    @MainActor
    func testSearchShowsProducts() {
        let app = launchApp()

        let searchTab = tabButton(identifier: "tab.search", germanTitle: "Suche", in: app)
        XCTAssertTrue(searchTab.waitForExistence(timeout: timeout))
        searchTab.tap()
        XCTAssertTrue(element("screen.search", in: app).waitForExistence(timeout: timeout))

        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "The search field is missing")
        field.tap()
        field.typeText("Office")

        XCTAssertTrue(productCard(in: app).waitForExistence(timeout: networkTimeout), "Typing \"Office\" shows no products")

        field.typeText("\n")
        XCTAssertTrue(element("screen.searchResults", in: app).waitForExistence(timeout: networkTimeout), "The results did not open")
        XCTAssertTrue(productCard(in: app).waitForExistence(timeout: networkTimeout), "The results show no products")
    }

    @MainActor
    func testProductDeepLinkOpensProduct() throws {
        let app = launchApp()
        XCTAssertTrue(element("screen.home", in: app).waitForExistence(timeout: timeout))

        let url = try XCTUnwrap(URL(string: "karinex://product/office-2024-professional-plus-key"))
        app.open(url)

        XCTAssertTrue(
            element("screen.product", in: app).waitForExistence(timeout: networkTimeout),
            "The deep link did not open the product"
        )
        let shopTab = tabButton(identifier: "tab.shop", germanTitle: "Shop", in: app)
        XCTAssertTrue(shopTab.isSelected, "Product links open in the Shop tab")
        XCTAssertTrue(app.buttons["product.addToCart"].waitForExistence(timeout: networkTimeout), "The product did not load")
    }

    // MARK: Helpers

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-kx.uitesting",
            "-kx.reset",
            "-AppleLanguages", "(de)",
            "-AppleLocale", "de_DE",
        ]
        app.launch()
        return app
    }

    /// `text` on one line (CI log formatters keep only the first line of a failure message),
    /// limited to `limit` characters.
    private static func singleLine(_ text: String, limit: Int = 12000) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return String(lines.joined(separator: " | ").prefix(limit))
    }

    /// Any element with `identifier`.
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// The first product card on screen (`product.card.<handle>`).
    @MainActor
    private func productCard(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'product.card.'")).firstMatch
    }

    /// The tab bar button with `identifier`, or with its German title, because SwiftUI does not
    /// forward a `tabItem` identifier to the button on every iOS release.
    @MainActor
    private func tabButton(identifier: String, germanTitle: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", identifier, germanTitle)
        return app.tabBars.firstMatch.buttons.matching(predicate).firstMatch
    }

    /// Waits until `element` matches `format`.
    @MainActor
    private func waitUntil(_ element: XCUIElement, matches format: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: format), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Closes the checkout sheet with Checkout Kit's close button, or by swiping it down.
    @MainActor
    private func closeCheckout(in app: XCUIApplication) {
        let predicate = NSPredicate(format: "label IN %@ OR identifier IN %@", ["Schließen", "Close"], ["Close", "close"])
        let close = app.navigationBars.buttons.matching(predicate).firstMatch
        if close.waitForExistence(timeout: timeout) {
            close.tap()
        } else {
            app.navigationBars.firstMatch.swipeDown(velocity: .fast)
        }
    }

    /// Swipes up until `element` can be tapped, for content below the fold.
    @MainActor
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable, attempts < 8 {
            app.swipeUp()
            attempts += 1
        }
    }
}
