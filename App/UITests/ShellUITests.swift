import XCTest

// MARK: - ShellUITests

/// Critical-path UI tests of the Phase 0 shell: the five tabs, their root screens, the hero call
/// to action and the money-back conditions.
///
/// The app runs with `-kx.uitesting` (fixed online network status, or offline with
/// `-kx.offline`), `-kx.reset` (no state from earlier runs) and German language and region, so
/// labels and layout are deterministic.
final class ShellUITests: XCTestCase {
    /// The tabs as the tests see them.
    private enum Tab: String, CaseIterable {
        case home
        case shop
        case search
        case cart
        case account

        /// Accessibility identifier of the tab bar button.
        var identifier: String {
            "tab.\(rawValue)"
        }

        /// German title of the tab bar button.
        var germanTitle: String {
            switch self {
            case .home: "Start"
            case .shop: "Shop"
            case .search: "Suche"
            case .cart: "Warenkorb"
            case .account: "Konto"
            }
        }

        /// Accessibility identifier of the tab's root screen.
        var screenIdentifier: String {
            switch self {
            case .home: "screen.home"
            case .shop: "screen.catalog"
            case .search: "screen.search"
            case .cart: "screen.cart"
            case .account: "screen.account"
            }
        }
    }

    private let timeout: TimeInterval = 10

    /// Accessibility identifier of the offline banner (`OfflineBannerModifier` in the app).
    private let offlineBannerIdentifier = "shell.offlineBanner"
    /// The German default message of the offline banner (DesignSystem String Catalog).
    private let offlineBannerMessage = "Sie sind offline. Bitte prüfen Sie Ihre Internetverbindung."

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: Tests

    @MainActor
    func testTabBarShowsFiveTabs() {
        let app = launchApp()

        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: timeout), "The tab bar did not appear")
        for tab in Tab.allCases {
            XCTAssertTrue(tabButton(tab, in: app).waitForExistence(timeout: timeout), "Missing tab bar button \(tab.identifier)")
        }
        XCTAssertEqual(app.tabBars.firstMatch.buttons.count, Tab.allCases.count)
        XCTAssertFalse(offlineBanner(in: app).exists, "The offline banner is shown although the device is online")
    }

    @MainActor
    func testEachTabShowsItsRootScreen() {
        let app = launchApp()
        XCTAssertTrue(screen(.home, in: app).waitForExistence(timeout: timeout), "Start is not the initial tab")

        for tab in Tab.allCases.reversed() {
            let button = tabButton(tab, in: app)
            XCTAssertTrue(button.waitForExistence(timeout: timeout), "Missing tab bar button \(tab.identifier)")
            button.tap()
            XCTAssertTrue(screen(tab, in: app).waitForExistence(timeout: timeout), "\(tab.screenIdentifier) did not appear")
            XCTAssertTrue(button.isSelected, "\(tab.identifier) is not selected after tapping it")
        }
    }

    @MainActor
    func testHeroCallToActionOpensShop() {
        let app = launchApp()
        XCTAssertTrue(screen(.home, in: app).waitForExistence(timeout: timeout))

        let callToAction = app.buttons["home.hero.cta"]
        XCTAssertTrue(callToAction.waitForExistence(timeout: timeout), "The hero call to action is missing")
        callToAction.tap()

        XCTAssertTrue(screen(.shop, in: app).waitForExistence(timeout: timeout), "The Shop screen did not appear")
        XCTAssertTrue(tabButton(.shop, in: app).isSelected, "The Shop tab is not selected")
    }

    @MainActor
    func testMoneyBackConditionsOpenAndClose() {
        let app = launchApp()
        XCTAssertTrue(screen(.home, in: app).waitForExistence(timeout: timeout))

        let showConditions = app.buttons["home.trust.conditions"]
        XCTAssertTrue(showConditions.waitForExistence(timeout: timeout), "The conditions button is missing")
        scrollIntoView(showConditions, in: app)
        showConditions.tap()

        let done = app.buttons["home.moneyback.done"]
        XCTAssertTrue(done.waitForExistence(timeout: timeout), "The money-back conditions sheet did not appear")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "home.moneyback").firstMatch.exists)
        done.tap()

        XCTAssertTrue(done.waitForNonExistence(timeout: timeout), "The conditions sheet did not close")
    }

    @MainActor
    func testOfflineBannerKeepsTheNavigationBarReachable() {
        let app = launchApp(extraArguments: ["-kx.offline"])

        let banner = offlineBanner(in: app)
        XCTAssertTrue(banner.waitForExistence(timeout: timeout), "The offline banner did not appear")

        let account = tabButton(.account, in: app)
        XCTAssertTrue(account.waitForExistence(timeout: timeout))
        account.tap()
        XCTAssertTrue(screen(.account, in: app).waitForExistence(timeout: timeout), "The tab bar is not usable while offline")

        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.waitForExistence(timeout: timeout), "The account screen has no navigation bar")
        XCTAssertLessThanOrEqual(
            banner.frame.maxY,
            navigationBar.frame.minY + 1,
            "The offline banner covers the navigation bar"
        )
    }

    @MainActor
    func testLaunchesInForcedDarkAppearance() {
        let app = launchApp(extraArguments: ["-kx.appearance", "dark"])

        XCTAssertTrue(screen(.home, in: app).waitForExistence(timeout: timeout))
        XCTAssertTrue(tabButton(.account, in: app).waitForExistence(timeout: timeout))
    }

    // MARK: Helpers

    @MainActor
    private func launchApp(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-kx.uitesting",
            "-kx.reset",
            "-AppleLanguages", "(de)",
            "-AppleLocale", "de_DE",
        ] + extraArguments
        app.launch()
        return app
    }

    /// The tab bar button of `tab`, found by its accessibility identifier. The German title is
    /// accepted as well, because SwiftUI does not guarantee that the identifier of a `tabItem`
    /// label reaches the tab bar button on every iOS release.
    @MainActor
    private func tabButton(_ tab: Tab, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", tab.identifier, tab.germanTitle)
        return app.tabBars.firstMatch.buttons.matching(predicate).firstMatch
    }

    /// The root screen of `tab`, found by its accessibility identifier.
    @MainActor
    private func screen(_ tab: Tab, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: tab.screenIdentifier).firstMatch
    }

    /// The offline banner, found by its accessibility identifier or, as a fallback, by its German
    /// message.
    @MainActor
    private func offlineBanner(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", offlineBannerIdentifier, offlineBannerMessage)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    /// Swipes up until `element` can be tapped, for content below the fold on small devices.
    @MainActor
    private func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) {
        var attempts = 0
        while !element.isHittable, attempts < 6 {
            app.swipeUp()
            attempts += 1
        }
    }
}
