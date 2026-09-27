import Core
import Foundation
@testable import KARINEX
import SwiftUI
import Testing

// MARK: - AppTab

@Suite("AppTab")
struct AppTabTests {
    @Test("Tabs are ordered Start, Shop, Suche, Warenkorb, Konto")
    func order() {
        #expect(AppTab.allCases == [.home, .shop, .search, .cart, .account])
    }

    @Test("Each tab has its SF Symbol")
    func systemImages() {
        #expect(AppTab.allCases.map(\.systemImage) == [
            "house",
            "square.grid.2x2",
            "magnifyingglass",
            "bag",
            "person.crop.circle",
        ])
    }

    @Test("Each tab has a unique accessibility identifier for UI tests")
    func accessibilityIdentifiers() {
        #expect(AppTab.allCases.map(\.accessibilityIdentifier) == [
            "tab.home",
            "tab.shop",
            "tab.search",
            "tab.cart",
            "tab.account",
        ])
    }

    @Test("German tab titles come from the app's String Catalog")
    func germanTitles() throws {
        let german = try localizationBundle("de")
        #expect(AppTab.allCases.map { $0.title(in: german) } == ["Start", "Shop", "Suche", "Warenkorb", "Konto"])
    }

    @Test("English tab titles come from the app's String Catalog")
    func englishTitles() throws {
        let english = try localizationBundle("en")
        #expect(AppTab.allCases.map { $0.title(in: english) } == ["Home", "Shop", "Search", "Basket", "Account"])
    }

    @Test("Titles in the current language are resolved, not raw keys")
    func currentLanguageTitlesResolve() {
        for tab in AppTab.allCases {
            #expect(!tab.title.isEmpty)
            #expect(!tab.title.hasPrefix("tab."))
        }
    }

    /// The `.lproj` folder of `language` inside the app bundle (the test host).
    private func localizationBundle(_ language: String) throws -> Bundle {
        let path = try #require(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try #require(Bundle(path: path))
    }
}

// MARK: - Shell behaviour

@Suite("App shell")
struct AppShellTests {
    @Test("The offline banner shows only for a known offline status")
    func offlineBannerPolicy() {
        #expect(OfflineBannerPolicy.isBannerPresented(for: .offline))
        #expect(!OfflineBannerPolicy.isBannerPresented(for: nil))
        #expect(!OfflineBannerPolicy.isBannerPresented(for: .online(isExpensive: false, isConstrained: false)))
        #expect(!OfflineBannerPolicy.isBannerPresented(for: .online(isExpensive: true, isConstrained: true)))
    }

    @Test("UI test runs are online unless -kx.offline is passed")
    func uiTestingNetworkStatus() {
        #expect(AppServices.uiTestingNetworkStatus(arguments: ["KARINEX", "-kx.uitesting"])
            == .online(isExpensive: false, isConstrained: false))
        #expect(AppServices.uiTestingNetworkStatus(arguments: ["KARINEX", "-kx.uitesting", AppServices.offlineArgument])
            == .offline)
    }

    @Test("Forced appearances map to SwiftUI color schemes")
    func forcedAppearance() {
        #expect(LaunchEnvironment.Appearance.light.colorScheme == .light)
        #expect(LaunchEnvironment.Appearance.dark.colorScheme == .dark)
        let dark = LaunchEnvironment(arguments: ["KARINEX", LaunchEnvironment.appearanceArgument, "dark"])
        #expect(dark.forcedAppearance?.colorScheme == .dark)
        #expect(LaunchEnvironment(arguments: ["KARINEX"]).forcedAppearance?.colorScheme == nil)
    }

    @MainActor
    @Test("The preview container runs tokenless against the live store configuration")
    func previewContainer() {
        let container = AppContainer.preview()

        #expect(container.configuration == .preview)
        #expect(container.configurationFailure == nil)
        #expect(container.storefrontClient.isTokenless)
    }
}
